#!/bin/sh
# Installs Pepper on Linux or macOS from a release's prebuilt archive.
#
#   curl -fsSL https://raw.githubusercontent.com/justinboswell/pepper/main/scripts/install.sh | sh
#   sh install.sh [--version <x.y.z> | --archive <file>] [--prefix <dir>]
#                 [--yes] [--no-modify-path] [--no-prerequisites]
#   sh install.sh --uninstall [--prefix <dir>]
#
# It downloads `pepper-<version>-<target>.tar.gz` for this machine (the
# newest release that has one, or --version's), checks it against its
# `.sha256`, unpacks it into ~/.pepper (bin/ and runtime/), and adds
# ~/.pepper/bin to the PATH in the shell's startup files. Running it again
# replaces the install; --uninstall removes it and those PATH lines.
#
# Linking a program needs a clang and the C library's development files.
# When there is no clang it offers to install one with the system's
# package manager (apt, dnf, yum, pacman or zypper; on macOS, Xcode's
# command line tools), asking first unless --yes is given. Last, it builds
# and runs a small program to show the install works, and fails if it
# cannot.
#
# Environment:
#   PEPPER_HOME             where to install (as --prefix); default ~/.pepper
#   GITHUB_TOKEN, GH_TOKEN  a token to download with, while the repository
#                           is private
#
# The whole script is a function called on its last line, so a download cut
# short runs nothing.
set -eu

REPO="justinboswell/pepper"
MARKER="# Added by the Pepper installer"

say() { printf 'pepper-install: %s\n' "$*"; }
warn() { printf 'pepper-install: warning: %s\n' "$*" >&2; }
die() { printf 'pepper-install: error: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Installs Pepper from a release's prebuilt archive.

usage: install.sh [--version <x.y.z> | --archive <file>] [--prefix <dir>]
                  [--yes] [--no-modify-path] [--no-prerequisites]
       install.sh --uninstall [--prefix <dir>]

Options:
  --version <x.y.z>   install this release (default: the newest with an archive for this machine)
  --archive <file>    install this downloaded archive instead, checked against <file>.sha256
  --prefix <dir>      install into <dir> (default: $PEPPER_HOME, else ~/.pepper)
  -y, --yes           install missing prerequisites without asking
  --no-modify-path    leave the shell startup files alone
  --no-prerequisites  neither check for nor install clang and OpenSSL
  --uninstall         remove the install and the PATH lines it added
  -h, --help          show this help
EOF
}

# Asks a yes/no question on the terminal (stdin is the script when piped
# into sh). Yes with --yes; no when there is no terminal to ask on.
ask() {
  [ "$assume_yes" = 1 ] && return 0
  if ! { : </dev/tty; } 2>/dev/null; then
    return 1
  fi
  printf 'pepper-install: %s [Y/n] ' "$1" >/dev/tty
  read -r answer </dev/tty || return 1
  case "$answer" in
    ''|y|Y|yes|Yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# Runs a command as root: directly when already root, else through sudo.
as_root() {
  if [ "$(id -u)" = 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    die "'$*' needs root, and there is no sudo"
  fi
}

token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"

# Downloads $1 to $2, with the token when there is one; $3, when given,
# is the Accept header (the API serves an asset's bytes for
# application/octet-stream).
fetch() {
  accept="${3:-*/*}"
  if command -v curl >/dev/null 2>&1; then
    if [ -n "$token" ]; then
      curl -fsSL -H "Authorization: Bearer $token" -H "Accept: $accept" -o "$2" "$1"
    else
      curl -fsSL -H "Accept: $accept" -o "$2" "$1"
    fi
  elif command -v wget >/dev/null 2>&1; then
    if [ -n "$token" ]; then
      wget -q --header="Authorization: Bearer $token" --header="Accept: $accept" -O "$2" "$1"
    else
      wget -q --header="Accept: $accept" -O "$2" "$1"
    fi
  else
    die "neither curl nor wget is installed"
  fi
}

# This machine's archive name: linux-x64, macos-arm64 or macos-x64.
detect_target() {
  case "$(uname -s)" in
    Linux) os=linux ;;
    Darwin) os=macos ;;
    *) die "unsupported system '$(uname -s)': on Windows run install.ps1 in PowerShell" ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) arch=x64 ;;
    arm64|aarch64) arch=arm64 ;;
    *) die "unsupported processor '$(uname -m)'" ;;
  esac
  # A Mac running this shell under Rosetta reports x86_64.
  if [ "$os" = macos ] && [ "$arch" = x64 ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = 1 ]; then
    arch=arm64
  fi
  if [ "$os" = linux ] && [ "$arch" = arm64 ]; then
    die "there is no prebuilt Pepper for Linux on arm64 yet; build it from source: https://github.com/$REPO#setting-up-a-development-environment"
  fi
  if [ "$os" = linux ] && ldd --version 2>&1 | grep -qi musl; then
    die "the prebuilt Pepper needs glibc 2.28 or newer, and this system uses musl; build it from source: https://github.com/$REPO#setting-up-a-development-environment"
  fi
  echo "$os-$arch"
}

# Finds the release to install and its two assets. Lists the releases
# (newest first; the repository also has `vsix-*` and `llvm-*` ones) and
# takes the first `v<x.y.z>` one, or --version's, that has this target's
# archive. Sets tag, archive, archive_url and checksum_url.
find_release() {
  releases="$work/releases.json"
  if ! fetch "https://api.github.com/repos/$REPO/releases?per_page=100" "$releases"; then
    [ -n "$token" ] || warn "while the repository is private, set GITHUB_TOKEN to a token that can read it"
    die "cannot list the releases of $REPO"
  fi
  # One line per asset: <tag> <API url> <download link>.
  awk '
    /"tag_name":/ { gsub(/.*"tag_name": *"|".*/, ""); tag = $0 }
    /"url": *"[^"]*\/releases\/assets\// { gsub(/.*"url": *"|".*/, ""); api = $0 }
    /"browser_download_url":/ { gsub(/.*"browser_download_url": *"|".*/, ""); print tag, api, $0 }
  ' "$releases" > "$work/assets.txt"
  tag=""
  while read -r candidate api url; do
    case "$candidate" in
      v[0-9]*.[0-9]*.[0-9]*) ;;
      *) continue ;;
    esac
    [ -z "$wanted_version" ] || [ "$candidate" = "v$wanted_version" ] || continue
    case "$url" in
      */"pepper-${candidate#v}-$target.tar.gz")
        tag="$candidate"
        archive="pepper-${candidate#v}-$target.tar.gz"
        archive_url=$(asset_url "$api" "$url")
        break
        ;;
    esac
  done < "$work/assets.txt"
  if [ -z "$tag" ]; then
    [ -z "$wanted_version" ] || die "release v$wanted_version has no pepper-$wanted_version-$target.tar.gz"
    die "no release of $REPO has a prebuilt Pepper for $target yet"
  fi
  checksum_url=""
  while read -r candidate api url; do
    if [ "$candidate" = "$tag" ] && [ "${url##*/}" = "$archive.sha256" ]; then
      checksum_url=$(asset_url "$api" "$url")
      break
    fi
  done < "$work/assets.txt"
  [ -n "$checksum_url" ] || die "release $tag has no $archive.sha256 to check the download against"
}

# Where to download an asset from: its API url with a token (a private
# repository's download links need one), else its download link.
asset_url() {
  if [ -n "$token" ]; then echo "$1"; else echo "$2"; fi
}

# Downloads a release asset from asset_url's url.
fetch_asset() {
  fetch "$1" "$2" application/octet-stream
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# A clang to link with, where pep-build looks for one (see
# crates/pepper-driver/src/linker.rs): on the PATH, or in an LLVM install
# folder off it.
have_clang() {
  command -v clang >/dev/null 2>&1 && return 0
  for candidate in /usr/lib/llvm-*/bin/clang /opt/homebrew/opt/llvm/bin/clang /usr/local/opt/llvm/bin/clang; do
    [ -x "$candidate" ] && return 0
  done
  for directory in $(echo "$PATH" | tr ':' ' '); do
    for candidate in "$directory"/clang-[0-9]*; do
      case "$candidate" in
        */clang-[0-9]|*/clang-[0-9][0-9]) [ -x "$candidate" ] && return 0 ;;
      esac
    done
  done
  return 1
}

# The command that installs clang and the C library's development files
# with this Linux's package manager, or nothing when it has none we know.
linux_toolchain_command() {
  if command -v apt-get >/dev/null 2>&1; then echo "apt-get install -y clang build-essential"
  elif command -v dnf >/dev/null 2>&1; then echo "dnf install -y clang gcc glibc-devel"
  elif command -v yum >/dev/null 2>&1; then echo "yum install -y clang gcc glibc-devel"
  elif command -v pacman >/dev/null 2>&1; then echo "pacman -S --needed --noconfirm clang gcc"
  elif command -v zypper >/dev/null 2>&1; then echo "zypper install -y clang gcc glibc-devel"
  fi
}

# Makes sure programs can be linked: a clang, and on macOS Xcode's command
# line tools (the SDK and linker). Offers to install what is missing.
check_toolchain() {
  case "$target" in
    macos-*)
      if xcode-select -p >/dev/null 2>&1; then
        return 0
      fi
      say "Linking programs needs Xcode's command line tools, which are not installed."
      if ask "Install them now (xcode-select --install opens an installer window)?"; then
        xcode-select --install || true
        warn "finish the command line tools' installer, then run 'pepper build' as usual"
      else
        warn "install them before building a program: xcode-select --install"
      fi
      ;;
    linux-*)
      if have_clang; then
        return 0
      fi
      command=$(linux_toolchain_command)
      say "Linking programs needs clang, which is not installed."
      if [ -z "$command" ]; then
        warn "install clang and your C library's development files with your package manager"
      elif ask "Install it now with 'sudo $command'?"; then
        # shellcheck disable=SC2086
        as_root $command || warn "'$command' failed; install clang yourself"
      else
        warn "install it before building a program: sudo $command"
      fi
      ;;
  esac
}

# OpenSSL 3, which the `tls` module loads when a program uses it. Only a
# note: nothing else needs it.
check_openssl() {
  case "$target" in
    linux-*)
      if { ldconfig -p 2>/dev/null || /sbin/ldconfig -p 2>/dev/null; } | grep -q 'libssl\.so\.3'; then
        return 0
      fi
      say "note: programs that use the 'tls' module need OpenSSL 3 (libssl.so.3), which was not found; install your distribution's OpenSSL 3 package to use it"
      ;;
    macos-*)
      for candidate in /opt/homebrew/opt/openssl@3/lib/libssl.3.dylib /usr/local/opt/openssl@3/lib/libssl.3.dylib /opt/local/lib/libssl.3.dylib; do
        [ -f "$candidate" ] && return 0
      done
      if command -v brew >/dev/null 2>&1 && ask "Programs that use the 'tls' module need OpenSSL 3. Install it with 'brew install openssl@3'?"; then
        brew install openssl@3 || warn "'brew install openssl@3' failed"
      else
        say "note: programs that use the 'tls' module need OpenSSL 3: brew install openssl@3"
      fi
      ;;
  esac
}

# The startup files that set the PATH for this user's shells.
profile_files() {
  echo "$HOME/.profile"
  [ -f "$HOME/.bashrc" ] && echo "$HOME/.bashrc"
  [ -f "$HOME/.bash_profile" ] && echo "$HOME/.bash_profile"
  if [ -f "$HOME/.zshrc" ] || [ "$(basename "${SHELL:-}")" = zsh ]; then
    echo "$HOME/.zshrc"
  fi
}

fish_file() {
  echo "${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/pepper.fish"
}

add_to_path() {
  for file in $(profile_files); do
    if [ -f "$file" ] && grep -qF "$MARKER" "$file"; then
      continue
    fi
    printf '\n%s\nexport PATH="%s/bin:$PATH"\n' "$MARKER" "$prefix" >> "$file"
    say "added $prefix/bin to the PATH in $file"
  done
  if command -v fish >/dev/null 2>&1; then
    file=$(fish_file)
    mkdir -p "$(dirname "$file")"
    printf '%s\nfish_add_path "%s/bin"\n' "$MARKER" "$prefix" > "$file"
    say "added $prefix/bin to the PATH in $file"
  fi
}

# Removes the marker line and the line after it from each startup file.
remove_from_path() {
  for file in $(profile_files); do
    [ -f "$file" ] && grep -qF "$MARKER" "$file" || continue
    awk -v marker="$MARKER" '
      $0 == marker { skip = 1; next }
      skip { skip = 0; next }
      { print }
    ' "$file" > "$file.pepper-tmp" && mv "$file.pepper-tmp" "$file"
    say "removed the PATH line from $file"
  done
  file=$(fish_file)
  if [ -f "$file" ] && grep -qF "$MARKER" "$file"; then
    rm -f "$file"
    say "removed $file"
  fi
}

uninstall() {
  if [ -d "$prefix" ]; then
    [ -f "$prefix/bin/pep-build" ] || die "$prefix does not look like a Pepper install (no bin/pep-build); remove it yourself"
    rm -rf "$prefix"
    say "removed $prefix"
  else
    say "nothing installed at $prefix"
  fi
  remove_from_path
}

# Builds and runs a program with the new install, from an empty folder.
verify() {
  mkdir -p "$work/hello"
  printf 'main(): int {\n    print("Pepper is installed.");\n    return 0;\n}\n' > "$work/hello/hello.pep"
  if (cd "$work/hello" && "$prefix/bin/pepper" build hello.pep -o hello && ./hello); then
    return 0
  fi
  die "Pepper is installed in $prefix, but could not build a program; see the error above"
}

main() {
  wanted_version=""
  prefix="${PEPPER_HOME:-$HOME/.pepper}"
  assume_yes=0
  modify_path=1
  prerequisites=1
  local_archive=""
  action=install
  while [ $# -gt 0 ]; do
    case "$1" in
      --version) [ $# -ge 2 ] || die "--version needs a version"; wanted_version="${2#v}"; shift ;;
      --version=*) wanted_version="${1#--version=}"; wanted_version="${wanted_version#v}" ;;
      --prefix) [ $# -ge 2 ] || die "--prefix needs a folder"; prefix="$2"; shift ;;
      --prefix=*) prefix="${1#--prefix=}" ;;
      -y|--yes) assume_yes=1 ;;
      --no-modify-path) modify_path=0 ;;
      --archive) [ $# -ge 2 ] || die "--archive needs a file"; local_archive="$2"; shift ;;
      --archive=*) local_archive="${1#--archive=}" ;;
      --no-prerequisites) prerequisites=0 ;;
      --uninstall) action=uninstall ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; die "unknown option '$1'" ;;
    esac
    shift
  done

  if [ "$action" = uninstall ]; then
    uninstall
    return
  fi

  target=$(detect_target) || exit 1
  work=$(mktemp -d "${TMPDIR:-/tmp}/pepper-install.XXXXXX")
  trap 'rm -rf "$work"' EXIT INT TERM

  if [ -n "$local_archive" ]; then
    [ -f "$local_archive" ] || die "no archive at $local_archive"
    [ -f "$local_archive.sha256" ] || die "no $local_archive.sha256 to check the archive against"
    archive=$(basename "$local_archive")
    cp "$local_archive" "$work/$archive"
    cp "$local_archive.sha256" "$work/$archive.sha256"
    version=${archive#pepper-}
    say "installing Pepper ${version%-"$target".tar.gz} ($target) into $prefix"
  else
    find_release
    say "installing Pepper ${tag#v} ($target) into $prefix"
    fetch_asset "$archive_url" "$work/$archive" || die "cannot download $archive"
    fetch_asset "$checksum_url" "$work/$archive.sha256" || die "cannot download $archive.sha256"
  fi
  expected=$(cut -d' ' -f1 < "$work/$archive.sha256")
  actual=$(sha256_of "$work/$archive")
  [ "$expected" = "$actual" ] || die "$archive does not match its checksum (expected $expected, got $actual)"

  tar -xzf "$work/$archive" -C "$work"
  unpacked="$work/${archive%.tar.gz}"
  [ -f "$unpacked/bin/pep-build" ] || die "$archive does not hold bin/pep-build"
  mkdir -p "$prefix"
  rm -rf "$prefix/bin" "$prefix/runtime"
  for entry in "$unpacked"/*; do
    rm -rf "$prefix/$(basename "$entry")"
    mv "$entry" "$prefix/"
  done
  if [ "$target" != "${target#macos}" ]; then
    # Unsigned binaries: a download's quarantine flag makes Gatekeeper
    # refuse to run them. curl sets none, but a copy made elsewhere may.
    xattr -dr com.apple.quarantine "$prefix" 2>/dev/null || true
  fi
  say "installed $("$prefix/bin/pepper" --version)"

  case ":$PATH:" in
    *":$prefix/bin:"*) ;;
    *)
      if [ "$modify_path" = 1 ]; then
        add_to_path
        say "open a new terminal, or run: export PATH=\"$prefix/bin:\$PATH\""
      else
        say "add $prefix/bin to your PATH to run pepper"
      fi
      ;;
  esac

  if [ "$prerequisites" = 1 ]; then
    check_toolchain
    check_openssl
  fi
  verify
}

main "$@"
