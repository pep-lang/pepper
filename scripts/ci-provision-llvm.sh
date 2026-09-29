#!/usr/bin/env bash
# CI-only LLVM provisioning.
#
# Windows has no package manager that ships a usable LLVM -- the llvm.org
# installer and the winget/choco packages carry neither llvm-config nor the
# component libraries (windows-latest has 2.4 GB of LLVM 20 with no
# llvm-config.exe and a single LLVM*.lib) -- so it installs the repo's prebuilt
# minimal package, falling back to the upstream archive when none is published.
#
# Linux and macOS need none of that: apt and Homebrew both carry complete LLVM
# dev packages, and setup-llvm.sh prefers them. Measured on the runner images,
# per LLVM major:
#
#   ubuntu-24.04   apt llvm-{18,19,20}-dev + libpolly   4-8s, 400-750 MB
#   macos-latest   brew llvm@{18..22}                   13-17s (llvm@20 preinstalled)
#
# All of those build the workspace and pass the suite, which is why nothing
# here downloads an 11.6 GB tarball any more.
#
# Either way this ends by running the normal setup script, which validates the
# prefix and writes .cargo/config.toml, so there is one source of truth for how
# cargo finds LLVM.
#
# The LLVM major comes from PEPPER_LLVM_MAJOR when set, else each setup
# script's own default. Needs GH_TOKEN on Windows to read release assets from a
# private repo.
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"

case "$(uname -s)" in
  Darwin|Linux)
    # Nothing to pre-stage: the setup script installs from apt/brew and only
    # reaches for an archive if the platform's package manager cannot serve
    # the requested major at all.
    exec bash scripts/setup-llvm.sh
    ;;
  MINGW*|MSYS*|CYGWIN*) ;;
  *) echo "unsupported host: $(uname -s)" >&2; exit 1 ;;
esac

# --- Windows ---------------------------------------------------------------

# The major decides which package to fetch, and the patch version decides where
# setup-llvm.ps1 will look for it. Both come from that script, so the package
# cannot land in a directory it never inspects. The CR strip matters -- a
# Windows checkout gives these files CRLF endings, and an anchored match would
# come back empty.
read_pin() {
  tr -d '\r' < scripts/setup-llvm.ps1 | sed -nE "$1" | head -1
}

major="${PEPPER_LLVM_MAJOR:-$(read_pin "s/^\\\$DefaultLlvmMajor = '([^']+)'.*/\\1/p")}"
[ -n "$major" ] || { echo "cannot read \$DefaultLlvmMajor from scripts/setup-llvm.ps1" >&2; exit 1; }

# The version table is `'<major>' = '<version>'`, one per line.
version=$(read_pin "s/^ *'$major' = '([^']+)'.*/\\1/p")
[ -n "$version" ] || { echo "no LLVM $major in the version table in scripts/setup-llvm.ps1" >&2; exit 1; }

# `tar` differs per host. Under Git bash on Windows, PATH finds GNU tar, which
# reads the `C:` of a Windows path as a remote host ("Cannot connect to C:
# resolve failed"). What keeps that from happening is the `cygpath` conversion
# below: every path handed to tar -- the prefix and the archive alike -- is in
# POSIX form, so no drive letter ever reaches it. Keep that conversion.
local_appdata=$(cygpath -u "$LOCALAPPDATA")
prefix="$local_appdata/pepper/llvm/$version"

platform=windows-x64
tag="llvm-$version"
asset="llvm-$version-$platform.tar.xz"

# A self-hosted runner keeps the prefix from its last job, and re-downloading
# and re-extracting it cost about a minute a job. The marker is written only
# after an extraction succeeds, so a job killed mid-extract leaves no marker and
# the next one installs afresh. setup-llvm.ps1 still validates the tree below.
marker="$prefix/.pepper-ci-installed"
if [ -f "$marker" ]; then
  echo "LLVM $version already installed at $prefix; skipping download"
  exec pwsh -File scripts/setup-llvm.ps1 -Llvm "$major"
fi

echo "Looking for prebuilt $asset in release $tag"
staging=$(mktemp -d)
if download_error=$(gh release download "$tag" --pattern "$asset" --dir "$staging" 2>&1); then
  echo "Installing prebuilt package to $prefix"
  mkdir -p "$prefix"
  archive=$(cd "$staging" && pwd)/$asset
  (cd "$prefix" && tar -xf "$archive")
  touch "$marker"
  rm -rf "$staging"
else
  rm -rf "$staging"
  # Only an absent release or asset justifies the fallback. An auth failure,
  # rate limit or dropped connection exits non-zero too, and treating those as
  # "nothing published" would quietly pay the multi-GB install this script
  # exists to avoid, while logging a reason that is simply false.
  #
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
      echo "No prebuilt package published for $platform LLVM $version; falling back to the archive."
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

# Validates whatever is now in the prefix, installs from the archive if the
# download did not happen, and writes .cargo/config.toml either way.
pwsh -File scripts/setup-llvm.ps1 -Llvm "$major"
