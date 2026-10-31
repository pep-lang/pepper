#!/bin/sh
# Installs Pepper on Linux or macOS from a release's prebuilt archive.
#
#   curl -fsSL https://raw.githubusercontent.com/pep-lang/pepper/main/scripts/install.sh | sh
#   sh install.sh [--version <x.y.z> | --archive <file>] [--prefix <dir>]
#                 [--yes] [--no-modify-path] [--no-prerequisites]
#   sh install.sh --uninstall [--prefix <dir>]
#
# It only bootstraps: it downloads this machine's toolchain archive,
# `pepper-<version>-<target>.tar.gz`, and the installer archive beside it,
# `pepper-install-<version>-<target>.tar.gz`, from the newest release that
# has both (or --version's), checks the installer against its `.sha256`,
# unpacks its `pep-install` into a temporary folder and runs
# `pep-install setup --archive <toolchain archive>` with the options given.
# pep-install checks the toolchain archive, installs it into
# ~/.pepper/toolchains/<version>, makes it the default, puts `pepper` and
# `pep-install` in ~/.pepper/bin, adds that to the PATH, offers to install
# what linking needs, and builds a program to check (see
# docs/src/tools/pep-install.md). --uninstall runs `pep-install uninstall`.
#
# Environment:
#   PEPPER_HOME             where to install (as --prefix); default ~/.pepper
#   GITHUB_TOKEN, GH_TOKEN  a token for GitHub's API, which raises its
#                           limit on requests an hour
#
# The whole script is a function called on its last line, so a download cut
# short runs nothing.
set -eu

REPO="pep-lang/pepper"
API="https://api.github.com/repos/$REPO"

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
  --version <x.y.z>   install this release, or a prerelease such as 0.4.0-dev (default: the newest
                      release with archives for this machine)
  --archive <file>    install this downloaded archive instead, checked against <file>.sha256, with
                      the installer archive pepper-install-<version>-<target>.tar.gz beside it
  --prefix <dir>      install into <dir> (default: $PEPPER_HOME, else ~/.pepper)
  -y, --yes           install missing prerequisites without asking
  --no-modify-path    leave the shell startup files alone
  --no-prerequisites  neither check for nor install clang and OpenSSL
  --uninstall         remove the install and the PATH lines it added
  -h, --help          show this help
EOF
}

token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"

# Downloads $1 to $2, with the token when there is one; $3, when given,
# is the Accept header (the API serves an asset's bytes for
# application/octet-stream). Sets status to the HTTP status (0 when no
# answer came) and fails unless it is 2xx; an error's body stays in $2.
fetch() {
  accept="${3:-*/*}"
  if command -v curl >/dev/null 2>&1; then
    if [ -n "$token" ]; then
      status=$(curl -sSL -w '%{http_code}' -H "Authorization: Bearer $token" -H "Accept: $accept" -o "$2" "$1") || status=0
    else
      status=$(curl -sSL -w '%{http_code}' -H "Accept: $accept" -o "$2" "$1") || status=0
    fi
  elif command -v wget >/dev/null 2>&1; then
    # -S prints each response's status line, the last one after redirects.
    if [ -n "$token" ]; then
      status=$(wget -S --header="Authorization: Bearer $token" --header="Accept: $accept" -O "$2" "$1" 2>&1 | awk '/^ *HTTP\// { s = $2 } END { print s + 0 }')
    else
      status=$(wget -S --header="Accept: $accept" -O "$2" "$1" 2>&1 | awk '/^ *HTTP\// { s = $2 } END { print s + 0 }')
    fi
  else
    die "neither curl nor wget is installed"
  fi
  [ "$status" -ge 200 ] && [ "$status" -lt 300 ]
}

# Gets the API url $1 into $2, whose answer must name the key $3. GitHub
# sometimes answers with 200 and `[]` (its list of releases does, often),
# so a failed or empty answer is asked again after each delay in $4
# (default: 2 and 5 seconds); a 404 is not. Fails with got, status and
# message set for api_die.
api_get() {
  got="$1"
  for delay in ${4:-2 5} 0; do
    if fetch "$1" "$2"; then
      grep -q "\"$3\"" "$2" && return 0
      message="no \"$3\" in its $(wc -c < "$2" | tr -d ' ') bytes, which start $(tr -d '\n' < "$2" | cut -c1-60)"
    else
      message=$(sed -n 's/.*"message": *"\([^"]*\)".*/\1/p' "$2" 2>/dev/null | head -1)
      [ "$status" != 404 ] || return 1
    fi
    [ "$delay" = 0 ] || { warn "GET $1 answered HTTP $status${message:+ ($message)}; trying again in ${delay}s"; sleep "$delay"; }
  done
  return 1
}

# Dies with what the last api_get got.
api_die() {
  die "GET $got answered HTTP $status${message:+: $message}"
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
    die "there is no prebuilt Pepper for Linux on arm64 yet; build it from source: https://docs.pepper-lang.dev/dev/contributing/building.html"
  fi
  if [ "$os" = linux ] && ldd --version 2>&1 | grep -qi musl; then
    die "the prebuilt Pepper needs glibc 2.28 or newer, and this system uses musl; build it from source: https://docs.pepper-lang.dev/dev/contributing/building.html"
  fi
  echo "$os-$arch"
}

# Lists the assets of the releases that may be installed, newest first, as
# one line per asset in $work/assets.txt: <tag> <API url> <download link>.
# That is --version's release; else the release of each `v<x.y.z>` tag,
# newest version first, up to the first with this target's archives. The
# list of releases often answers with no releases (#196), so it is asked,
# more patiently, only when the tags cannot be.
list_assets() {
  releases="$work/releases.json"
  : > "$work/assets.txt"
  if [ -n "$wanted_version" ]; then
    api_get "$API/releases/tags/v$wanted_version" "$releases" tag_name || api_die
    parse_assets
  elif api_get "$API/git/matching-refs/tags/v" "$work/tags.json" ref; then
    for candidate in $(tr ',' '\n' < "$work/tags.json" \
        | sed -n 's|.*"ref": *"refs/tags/\(v[0-9]*\.[0-9]*\.[0-9]*\)".*|\1|p' \
        | sort -t. -k1.2,1nr -k2,2nr -k3,3nr); do
      if api_get "$API/releases/tags/$candidate" "$releases" tag_name; then
        parse_assets
        has_archives "$candidate" && return
      elif [ "$status" != 404 ]; then
        api_die
      fi
    done
  else
    api_get "$API/releases?per_page=100" "$releases" tag_name "2 5 10 20 30" || api_die
    parse_assets
  fi
}

# Appends the assets of the release, or list of releases, in $releases to
# $work/assets.txt. One field per line, whether the JSON comes
# pretty-printed or compact; value(key) is the string after `"key":` on the
# line.
parse_assets() {
  tr ',' '\n' < "$releases" | awk '
    function value(key) { sub(".*\"" key "\": *\"", ""); sub(/".*/, ""); return $0 }
    /"tag_name":/ { tag = value("tag_name") }
    /"url": *"[^"]*\/releases\/assets\// { api = value("url") }
    /"browser_download_url":/ { print tag, api, value("browser_download_url") }
  ' >> "$work/assets.txt"
}

# Whether the release $1 has this target's toolchain and installer archives.
has_archives() {
  [ -n "$(asset_url "$1" "pepper-${1#v}-$target.tar.gz")" ] && [ -n "$(asset_url "$1" "pepper-install-${1#v}-$target.tar.gz")" ]
}

# Where to download the asset $2 of the release $1 from, or nothing when it
# has none: its API url with a token (a private repository's download links
# need one), else its download link.
asset_url() {
  while read -r candidate api url; do
    if [ "$candidate" = "$1" ] && [ "${url##*/}" = "$2" ]; then
      if [ -n "$token" ]; then echo "$api"; else echo "$url"; fi
      return
    fi
  done < "$work/assets.txt"
}

# Finds the release to install: the first `v<x.y.z>` one, or --version's,
# with this target's toolchain and installer archives. A prerelease such
# as `v0.4.0-dev` is taken only when --version names it. Sets tag.
find_release() {
  tag=""
  for candidate in $(cut -d' ' -f1 "$work/assets.txt" | uniq); do
    case "$candidate" in
      v[0-9]*.[0-9]*.[0-9]*) ;;
      *) continue ;;
    esac
    case "$candidate" in
      *-*) [ "$candidate" = "v$wanted_version" ] || continue ;;
    esac
    [ -z "$wanted_version" ] || [ "$candidate" = "v$wanted_version" ] || continue
    has_archives "$candidate" || continue
    tag="$candidate"
    return
  done
  [ -z "$wanted_version" ] || die "release v$wanted_version has no pepper-$wanted_version-$target.tar.gz and pepper-install-$wanted_version-$target.tar.gz"
  die "no release of $REPO has a prebuilt Pepper and its installer for $target yet"
}

# Downloads the asset $1 of release $tag, and its .sha256, into $work.
fetch_asset() {
  for name in "$1" "$1.sha256"; do
    url=$(asset_url "$tag" "$name")
    [ -n "$url" ] || die "release $tag has no $name"
    fetch "$url" "$work/$name" application/octet-stream || die "cannot download $name (HTTP $status)"
  done
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# Checks the installer archive $1 against its .sha256 and unpacks its
# pep-install into $work/installer.
unpack_installer() {
  [ -f "$1.sha256" ] || die "no $1.sha256 to check the installer against"
  expected=$(cut -d' ' -f1 < "$1.sha256")
  actual=$(sha256_of "$1")
  [ "$expected" = "$actual" ] || die "$(basename "$1") does not match its checksum (expected $expected, got $actual)"
  mkdir -p "$work/installer"
  tar -xzf "$1" -C "$work/installer" pep-install
  installer="$work/installer/pep-install"
}

main() {
  wanted_version=""
  prefix="${PEPPER_HOME:-$HOME/.pepper}"
  local_archive=""
  action=install
  setup_options=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --version) [ $# -ge 2 ] || die "--version needs a version"; wanted_version="${2#v}"; shift ;;
      --version=*) wanted_version="${1#--version=}"; wanted_version="${wanted_version#v}" ;;
      --prefix) [ $# -ge 2 ] || die "--prefix needs a folder"; prefix="$2"; shift ;;
      --prefix=*) prefix="${1#--prefix=}" ;;
      -y|--yes) setup_options="$setup_options --yes" ;;
      --no-modify-path) setup_options="$setup_options --no-modify-path" ;;
      --archive) [ $# -ge 2 ] || die "--archive needs a file"; local_archive="$2"; shift ;;
      --archive=*) local_archive="${1#--archive=}" ;;
      --no-prerequisites) setup_options="$setup_options --no-prerequisites" ;;
      --uninstall) action=uninstall ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; die "unknown option '$1'" ;;
    esac
    shift
  done
  export PEPPER_HOME="$prefix"

  # A home set up by pep-install uninstalls itself.
  if [ "$action" = uninstall ] && "$prefix/bin/pep-install" uninstall --help >/dev/null 2>&1; then
    "$prefix/bin/pep-install" uninstall
    return
  fi

  target=$(detect_target) || exit 1
  work=$(mktemp -d "${TMPDIR:-/tmp}/pepper-install.XXXXXX")
  trap 'rm -rf "$work"' EXIT INT TERM

  if [ -n "$local_archive" ]; then
    [ -f "$local_archive" ] || die "no archive at $local_archive"
    archive=$(cd "$(dirname "$local_archive")" && pwd)/$(basename "$local_archive")
    installer_archive="$(dirname "$archive")/pepper-install-$(basename "$archive" | sed 's/^pepper-//')"
    [ -f "$installer_archive" ] || die "no installer archive $installer_archive beside $archive"
  else
    list_assets
    find_release
    say "downloading Pepper ${tag#v} ($target)"
    installer_archive="$work/pepper-install-${tag#v}-$target.tar.gz"
    fetch_asset "$(basename "$installer_archive")"
    archive=""
    if [ "$action" = install ]; then
      archive="$work/pepper-${tag#v}-$target.tar.gz"
      fetch_asset "$(basename "$archive")"
    fi
  fi
  unpack_installer "$installer_archive"

  if [ "$action" = uninstall ]; then
    "$installer" uninstall
    return
  fi
  # shellcheck disable=SC2086
  "$installer" setup --archive "$archive" $setup_options
}

main "$@"
