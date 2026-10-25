#!/usr/bin/env bash
# Provision LLVM 20, the LLVM the compiler (pepc, through the pepper-llvm
# package) links against, and point the scripts at it. macOS / Linux
# counterpart of scripts/setup-llvm.ps1.
#
# Order of preference, cheapest first:
#
#   1. an LLVM of the wanted major already on this machine
#   2. the platform's own LLVM dev package -- apt llvm-<major>-dev, or
#      Homebrew llvm@<major>. On both CI images this is seconds and a few
#      hundred MB, and on macos-latest llvm@20 is already there.
#   3. the upstream release archive, unpacking only the files the build needs.
#      The Linux tarball is 11.6 GB extracted and 9 GB of that is tools this
#      project never invokes, which is what used to exhaust a CI runner's disk.
#
# Usage:
#   ./scripts/setup-llvm.sh [options]
#
# Options:
#   --devtools      also make sure a debugger (lldb) is available; equivalent to
#                   PEPPER_SETUP_DEVTOOLS=1. Off by default: the build does not
#                   need it.
#   --no-devtools   skip that, overriding PEPPER_SETUP_DEVTOOLS.
#   --no-packages   never invoke apt/brew; use what is installed or the archive.
#   --check         report the LLVM it would use and what .pep/llvm-prefix
#                   records, and exit (non-zero unless they agree) without
#                   changing anything.
#   -h, --help      this text.
#
# PEPPER_LLVM_VERSION=<major.minor.patch> provisions that LLVM instead of the
# pinned one (llvm-package.yml uses it to package another release).
#
# It records the prefix it settles on in .pep/llvm-prefix (one line, read by
# scripts/pepper-tests.sh, the release build and the workflows).
#
# Idempotent: re-running with a usable toolchain only rewrites that.
set -euo pipefail

# The one LLVM major Pepper builds with: the one pepper-llvm binds
# (`[Link("LLVM-20")]`). apt and Homebrew both serve it cheaply.
# scripts/release-build.sh, ci-provision-llvm.sh and llvm-package.yml read
# this line, so keep its shape.
LLVM_MAJOR="20"

# The patch version, used only when falling back to the release archive: the
# newest patch release upstream published for LLVM_MAJOR.
#
# This line is parsed by release-build.sh and llvm-package.yml, so keep the
# `<major>) echo <version>` shape.
archive_version() {
    case "$1" in
        20) echo "20.1.8" ;;
        *) return 1 ;;
    esac
}

if [ -n "${PEPPER_LLVM_VERSION:-}" ]; then
    LLVM_MAJOR="${PEPPER_LLVM_VERSION%%.*}"
    archive_version() { [ "$1" = "$LLVM_MAJOR" ] && echo "$PEPPER_LLVM_VERSION"; }
fi

# CPython minor version liblldb is linked against in the LLVM releases; only
# used to make the "lldb won't start" hint concrete.
LLDB_PYTHON_MINOR="11"

# PEPPER_SETUP_DEVTOOLS lets a dev opt in once (shell profile / CI) instead of
# remembering the flag on every run.
DEVTOOLS=0
case "${PEPPER_SETUP_DEVTOOLS:-}" in
    ""|0|false|no) ;;
    *) DEVTOOLS=1 ;;
esac

WANT_MAJOR="$LLVM_MAJOR"
USE_PACKAGES=1
CHECK=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --devtools) DEVTOOLS=1 ;;
        --no-devtools) DEVTOOLS=0 ;;
        --no-packages) USE_PACKAGES=0 ;;
        --check) CHECK=1 ;;
        -h|--help)
            sed -n '2,/^set -euo pipefail/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "unknown argument: $1" >&2
            exit 2
            ;;
    esac
    shift
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/pepper"
CACHE_DIR="$ROOT/cache"

# --- what "usable" means ----------------------------------------------------

# The compiler does not just need llvm-config: pepc links the LLVM library
# (the shared one in a development build, and in the release build every
# static component library `llvm-config --link-static --libnames` names,
# scripts/release-build.sh), and the headers come with a complete install.
# So check the prefix the way those builds consume it, not merely that
# llvm-config exists.
#
# Which link mode matters is subtle. Static is checked first, and shared
# only when `llvm-config --libnames --link-static` *fails*, not when the
# files it names are missing. Debian's llvm-N-dev is exactly that trap:
# --link-static succeeds and names Polly's archives, which live in
# libpolly-N-dev, so a prefix that looks fine by any "some link mode works"
# test fails a static link with
#
#   error: could not find native static library `Polly`
#
# Accepting such a prefix also skips the apt install that would have fixed it.
# Rejecting it makes the script install llvm-20-dev and libpolly-20-dev and
# try again.
#
# Prints nothing and returns 1 if unusable; prints the prefix if usable.
usable_llvm() {
    local config="$1" want="$2"
    [[ -x "$config" ]] || return 1

    local version major prefix libdir includedir
    version="$("$config" --version 2>/dev/null)" || return 1
    major="${version%%.*}"
    [[ "$major" == "$want" ]] || return 1

    prefix="$("$config" --prefix 2>/dev/null)" || return 1
    libdir="$("$config" --libdir 2>/dev/null)" || return 1
    includedir="$("$config" --includedir 2>/dev/null)" || return 1

    [[ -e "$includedir/llvm-c/Core.h" ]] || return 1
    [[ -e "$includedir/llvm/Config/llvm-config.h" ]] || return 1

    # Static unless llvm-config cannot report it.
    local names
    if ! names="$("$config" --libnames --link-static 2>/dev/null)" || [[ -z "$names" ]]; then
        names="$("$config" --libnames --link-shared 2>/dev/null)" || return 1
        [[ -n "$names" ]] || return 1
    fi
    local name
    for name in $names; do
        [[ -e "$libdir/$name" ]] || return 1
    done

    printf '%s' "$prefix"
}

# Every llvm-config worth trying, for one major.
llvm_candidates() {
    local major="$1"
    echo "llvm-config-$major"
    echo "/usr/lib/llvm-$major/bin/llvm-config"
    echo "/opt/homebrew/opt/llvm@$major/bin/llvm-config"
    echo "/usr/local/opt/llvm@$major/bin/llvm-config"
    echo "$ROOT/llvm/$(archive_version "$major" 2>/dev/null)/bin/llvm-config"
    if command -v brew >/dev/null 2>&1; then
        local brew_prefix
        for formula in "llvm@$major" llvm; do
            brew_prefix="$(brew --prefix "$formula" 2>/dev/null || true)"
            [[ -n "$brew_prefix" ]] && echo "$brew_prefix/bin/llvm-config"
        done
    fi
    # Unversioned last: it is whatever the machine happens to default to, and
    # is only accepted if its major matches what we are looking for anyway.
    echo "llvm-config"
}

find_llvm() {
    local major="$1" candidate prefix

    # Collected before the loop rather than piped into it: returning from the
    # middle of a `while read` leaves llvm_candidates writing to a closed pipe,
    # which printed two "echo: write error: Broken pipe" lines into every CI
    # log on the common path where the first candidate is the answer.
    local candidates=()
    while read -r candidate; do
        [[ -n "$candidate" ]] && candidates+=("$candidate")
    done < <(llvm_candidates "$major")

    for candidate in "${candidates[@]}"; do
        # A bare name has to be resolved through PATH first.
        if [[ "$candidate" != /* ]]; then
            candidate="$(command -v "$candidate" 2>/dev/null || true)"
            [[ -n "$candidate" ]] || continue
        fi
        if prefix="$(usable_llvm "$candidate" "$major")"; then
            printf '%s' "$prefix"
            return 0
        fi
    done
    return 1
}

# --- package managers -------------------------------------------------------

# apt ships Polly separately, and llvm-config names Polly's libraries in
# --link-static output, so llvm-N-dev alone is not a complete static prefix.
# clang and build-essential are the link driver and the libc/startup objects
# it needs; both runner images have them, a fresh desktop may not.
apt_install() {
    local major="$1" pkgs="llvm-$major-dev" candidate

    # LC_ALL=C: apt translates its output, so "Candidate:" is "Kandidat:" on a
    # German desktop and this would conclude the package does not exist --
    # silently downgrading an 8-second apt install to a ~1 GB archive download.
    candidate="$(LC_ALL=C apt-cache policy "llvm-$major-dev" 2>/dev/null | awk '/Candidate:/ {print $2}')"
    [[ -n "$candidate" && "$candidate" != "(none)" ]] || return 1

    # Read with awk, like the check above, rather than piping into `grep -q`.
    # grep -q exits on its first match, apt-cache then dies of SIGPIPE, and
    # under `set -o pipefail` the pipeline reports 141 -- so this test came
    # back false whenever apt-cache still had output buffered. It is a race,
    # which is what made it so confusing: the same runner image installed
    # libpolly on one run and skipped it on the next, and skipping it makes
    # usable_llvm reject the apt prefix and fall all the way back to a ~1 GB
    # archive download whose LTO libraries then stall the linker.
    local polly
    polly="$(LC_ALL=C apt-cache policy "libpolly-$major-dev" 2>/dev/null | awk '/Candidate:/ {print $2}')"
    if [[ -n "$polly" && "$polly" != "(none)" ]]; then
        pkgs="$pkgs libpolly-$major-dev"
    fi
    # The link driver, and the libc/startup objects and `ld` it needs. Both
    # runner images have them; a fresh desktop may not. Checked by command
    # rather than by package, since a locally built clang counts.
    command -v clang >/dev/null 2>&1 || pkgs="$pkgs clang"
    command -v cc >/dev/null 2>&1 || pkgs="$pkgs build-essential"

    echo "Installing $pkgs (apt) ..."
    local sudo=""
    [[ "$(id -u)" != "0" ]] && sudo="sudo"
    apt_get update -qq || return 1
    # shellcheck disable=SC2086 # deliberate word splitting of the package list
    apt_get install -y $pkgs || return 1
}

# apt-get, as `$sudo`, waiting for another apt-get on this host (CI runs
# several runners per host, and a release runs the LLVM matrix twice side by
# side): dpkg's lock is waited for up to 5 minutes, and `update`'s list lock,
# which no option waits for, by retrying up to 10 times. A download that
# stalls for 30 seconds is retried, up to 3 times, rather than left to hang
# on a slow mirror (#194). apt has no low-speed limit, though: a mirror that
# trickles a byte every few seconds never trips the timeout, and only the CI
# step's own timeout-minutes ends it.
apt_get() {
    local tries=0
    until $sudo apt-get -o DPkg::Lock::Timeout=300 -o Acquire::Retries=3 -o Acquire::http::Timeout=30 "$@"; do
        tries=$((tries + 1))
        if (( tries >= 10 )); then
            return 1
        fi
        echo "apt-get $1 failed (another apt-get may hold its lock); retrying in 15s" >&2
        sleep 15
    done
}

brew_install() {
    local major="$1" formula="llvm@$major"
    command -v brew >/dev/null 2>&1 || return 1
    brew info --formula "$formula" >/dev/null 2>&1 || return 1
    echo "Installing $formula (brew) ..."
    brew install "$formula" || return 1
}

install_via_packages() {
    local major="$1"
    case "$(uname -s)" in
        Linux) command -v apt-get >/dev/null 2>&1 && apt_install "$major" ;;
        Darwin) brew_install "$major" ;;
        *) return 1 ;;
    esac
}

# --- release archive (last resort) ------------------------------------------

# Asset naming is not consistent across LLVM releases: 20.x names its
# archives LLVM-<v>-Linux-X64 / Linux-ARM64 / macOS-ARM64 (no macOS-X64),
# while older releases used clang+llvm-<v>-<triple>. Both schemes encode the
# platform differently; this matches either.
platform_pattern() {
    local os arch
    os="$(uname -s)"
    arch="$(uname -m)"
    case "$os/$arch" in
        Darwin/arm64)              printf 'macOS-ARM64|arm64-apple-macos' ;;
        Darwin/x86_64)             printf 'macOS-X64|x86_64-apple-darwin' ;;
        Linux/x86_64)              printf 'Linux-X64|x86_64-linux-gnu' ;;
        Linux/aarch64|Linux/arm64) printf 'Linux-ARM64|aarch64-linux-gnu' ;;
        *)
            echo "no prebuilt LLVM for $os/$arch." >&2
            echo "Install LLVM with llvm-config yourself (e.g. 'brew install llvm@$LLVM_MAJOR'" >&2
            echo "or https://apt.llvm.org) and re-run this script." >&2
            return 1
            ;;
    esac
}

# An already-downloaded archive for this version and platform, if any.
#
# Checked before the API lookup below, because the caches CI restores exist
# precisely so a repeat run skips the download: resolving the name online first
# would make an offline or rate-limited run fail with the tarball already on
# disk.
cached_asset() {
    local version="$1" pattern="$2" path base
    for path in "$CACHE_DIR"/*"$version"*.tar.xz; do
        [[ -f "$path" ]] || continue
        base="${path##*/}"
        case "$base" in LLVM-*|clang+llvm-*) ;; *) continue ;; esac
        # `grep -E … >/dev/null`, not `grep -qE`: -q exits on the first match
        # and can SIGPIPE the producer, which pipefail then reports as a
        # failed test. Same hazard as the apt and tar checks above.
        if printf '%s' "$base" | grep -E "$pattern" >/dev/null; then
            printf '%s' "$base"
            return 0
        fi
    done
    return 1
}

# Resolve the asset name from the release's own listing.
#
# Unauthenticated: llvm-project is public, and this runs immediately before
# downloading ~1 GB from the same host. Names only -- no jq, which is not
# guaranteed present.
resolve_release_asset() {
    local version="$1" pattern="$2" body err code names modern legacy
    body="$(mktemp)"
    err="$(mktemp)"

    # No -f: the status is wanted, not hidden, so the three failure modes can
    # be told apart. Collapsing them into "cannot reach the API" sends the
    # reader to retry a rate limit that will not clear for an hour.
    if ! code="$(curl -sS -o "$body" -w '%{http_code}' \
        "https://api.github.com/repos/llvm/llvm-project/releases/tags/llvmorg-$version" \
        2>"$err")"; then
        echo "cannot reach the GitHub API: $(head -1 "$err")" >&2
        rm -f "$body" "$err"
        return 1
    fi
    rm -f "$err"

    case "$code" in
        200) ;;
        403|429)
            echo "GitHub API rate limit reached (HTTP $code) resolving the LLVM $version asset." >&2
            echo "Wait, or install LLVM $version from your package manager instead." >&2
            rm -f "$body"
            return 1
            ;;
        404)
            echo "upstream has no release llvmorg-$version (HTTP 404)." >&2
            rm -f "$body"
            return 1
            ;;
        *)
            echo "GitHub API returned HTTP $code resolving the LLVM $version asset." >&2
            rm -f "$body"
            return 1
            ;;
    esac

    # A 200 that is not a release listing -- a captive portal or proxy serving
    # HTML -- would otherwise fall through to "publishes no build", which is a
    # false statement about upstream rather than about the response.
    if ! grep -q '"tag_name"' "$body"; then
        echo "the GitHub API returned something that is not a release listing." >&2
        echo "A proxy or captive portal intercepting api.github.com would do this." >&2
        rm -f "$body"
        return 1
    fi

    names="$(grep -oE '"name": *"(LLVM|clang\+llvm)-[^"]+\.tar\.xz"' "$body" \
             | sed -E 's/.*"(.*)"/\1/' | grep -E "$pattern" || true)"
    rm -f "$body"

    # Prefer the modern scheme explicitly. `sort -r` looked like it did this
    # but does the opposite under byte collation -- 'c' > 'L' -- and the answer
    # would have flipped with the locale.
    #
    # First line taken by expansion rather than `head -1`: under pipefail a
    # reader that exits early makes the producer die of SIGPIPE and the whole
    # pipeline report 141.
    modern="$(printf '%s\n' "$names" | grep -E '^LLVM-' || true)"
    legacy="$(printf '%s\n' "$names" | grep -E '^clang\+llvm-' || true)"
    if [[ -n "$modern" ]]; then
        printf '%s' "${modern%%$'\n'*}"
    elif [[ -n "$legacy" ]]; then
        printf '%s' "${legacy%%$'\n'*}"
    else
        echo "LLVM $version publishes no build for $(uname -s)/$(uname -m)." >&2
        echo "Install LLVM $version from your package manager instead." >&2
        return 1
    fi
}

# Only the members the build consumes: llvm-config for discovery, the
# libraries for linking, and the headers. Same set as scripts/package-llvm.sh,
# which prebuilds this for CI.
#
# clang is skipped on purpose -- the compiler's link driver
# (tools/compiler/driver/linker.pep) prefers the prefix's clang but falls back
# to PATH, and every platform that gets this far has one.
archive_members() {
    printf '%s\n' \
        '*/bin/llvm-config' \
        '*/lib/libLLVM*.a' \
        '*/lib/libLLVM*.so*' \
        '*/lib/libLLVM*.dylib' \
        '*/lib/libPolly*.a' \
        '*/include/llvm-c/*' \
        '*/include/llvm/Config/*'
}

# Sets ARCHIVE_PREFIX rather than printing the prefix, deliberately. Returning
# it on stdout would mean calling this in a command substitution, and bash does
# not inherit errexit into one unless `inherit_errexit` is set: a failing curl,
# mv or tar would be swallowed and provisioning would carry on with a partial
# tree. It also let progress messages end up captured *as* the prefix, which
# broke the archive path outright.
ARCHIVE_PREFIX=""
install_from_archive() {
    local major="$1" version asset pattern url archive prefix
    version="$(archive_version "$major")"
    pattern="$(platform_pattern)" || return 1
    prefix="$ROOT/llvm/$version"
    mkdir -p "$CACHE_DIR"

    if asset="$(cached_asset "$version" "$pattern")"; then
        archive="$CACHE_DIR/$asset"
        echo "Using cached $archive"
    else
        asset="$(resolve_release_asset "$version" "$pattern")" || return 1
        archive="$CACHE_DIR/$asset"
        url="https://github.com/llvm/llvm-project/releases/download/llvmorg-$version/$asset"
        echo "Downloading $asset ..."
        # Downloaded to .part and renamed, so an interrupted transfer is never
        # picked up as a cached archive by the lookup above.
        curl -L --fail --progress-bar -o "$archive.part" "$url"
        mv "$archive.part" "$archive"
    fi

    echo "Unpacking the build's LLVM files to $prefix ..."
    rm -rf "$prefix"
    mkdir -p "$prefix"
    local members=()
    while read -r member; do members+=("$member"); done < <(archive_members)

    # A member pattern that matches nothing is an error to both tars -- GNU
    # exits 2, bsdtar 1 -- and one of the shared-library patterns can never
    # match, since no release carries .dylib on Linux or .so on macOS. Those
    # complaints are expected and their output is suppressed; anything else is
    # a real failure and is reported. What was actually extracted is then
    # judged by usable_llvm, which is the check that matters.
    # Tolerated wording, per implementation:
    #   GNU tar  "<pattern>: Not found in archive" + "Exiting with failure status
    #            due to previous errors"          (exit 2)
    #   bsdtar   "<pattern>: Not found in archive" + "Error exit delayed from
    #            previous errors"                 (exit 1)
    # Missing the bsdtar line made this return 1 on every macOS run, since
    # `*/lib/libLLVM*.so*` can never match a macOS release.
    #
    # A nonzero exit with no output at all -- a signal death, say -- is a real
    # failure, not a tolerated one: an empty log would otherwise slip through
    # the filter below and be reported later as a merely incomplete tree.
    # Assembled into one always-non-empty array rather than expanding a
    # possibly-empty "${wildcards[@]}": on bash 3.2 -- which is what
    # /bin/bash still is on macOS, including the runner image -- expanding an
    # empty array under `set -u` is a fatal "unbound variable", and wildcards
    # is empty on exactly the hosts whose tar is bsdtar. That aborted the
    # archive tier on macOS before tar ran.
    #
    # LC_ALL=C because the tolerated wording below is GNU tar's English
    # message text, which gettext translates: on a non-English desktop every
    # Linux archive run -- all of which produce an unmatched-pattern
    # complaint, since `*.dylib` cannot match -- would be reported as a failed
    # extraction.
    local tar_log status=0 unexpected
    local tar_args=(-xf "$archive" -C "$prefix" --strip-components=1)
    # Captured, not piped into `grep -q`: that exits on the first line, tar
    # dies of SIGPIPE writing the rest of its banner, and pipefail turns the
    # test false -- which would drop --wildcards on a GNU host and leave tar
    # treating every member pattern as a literal filename.
    local tar_version
    tar_version="$(tar --version 2>/dev/null || true)"
    case "$tar_version" in *GNU*) tar_args+=(--wildcards) ;; esac
    tar_args+=("${members[@]}")
    tar_log="$(LC_ALL=C tar "${tar_args[@]}" 2>&1)" || status=$?

    # Collected into a variable rather than ending the pipeline in `grep -q .`:
    # that exits on the first surviving line, the upstream grep dies of SIGPIPE,
    # and under pipefail the pipeline reports 141 -- so a tar failure chatty
    # enough to fill the 64 KiB pipe buffer (ENOSPC repeated per member, say)
    # was classified as tolerated and its output never shown.
    unexpected="$(printf '%s\n' "$tar_log" \
        | grep -vE 'Not found in archive|Exiting with failure status|Error exit delayed|^$' \
        || true)"
    if [[ "$status" != "0" ]] && { [[ -z "$tar_log" ]] || [[ -n "$unexpected" ]]; }; then
        [[ -n "$tar_log" ]] && printf '%s\n' "$tar_log" >&2
        echo "extraction of $archive failed (tar exit $status)" >&2
        return 1
    fi

    # The modern release tarballs are built with LTO, so their static
    # libraries are LLVM bitcode rather than native objects. Apple's linker
    # reads that bitcode with its own (older) libLTO and rejects it:
    #
    #   ld: could not parse bitcode object file ...: 'Unknown attribute kind
    #   (105) (Producer: 'LLVM22.1.8' Reader: 'LLVM APPLE_1_2100.1.1.101_0')'
    #
    # Measured on macos-latest with LLVM 22: the unpack succeeds and the build
    # then fails at link. Homebrew's llvm@<major> is built without LTO and
    # works, which is why it is preferred -- this path only runs on a Mac
    # without brew, or with --no-packages. The prefix's own clang could read
    # the bitcode, but the keep-set deliberately excludes clang (gigabytes to
    # ship a compiler used only as a link driver), so there is nothing local
    # to link with. Warn rather than fail: a future Xcode whose libLTO is
    # newer than the archive's producer would work.
    if [[ "$(uname -s)" == "Darwin" ]]; then
        echo "warning: these release libraries are LTO bitcode, which Apple's linker" >&2
        echo "  usually cannot read ('could not parse bitcode object file' at link time)." >&2
        echo "  If that happens, install LLVM $major with Homebrew instead:" >&2
        echo "    brew install llvm@$major && ./scripts/setup-llvm.sh" >&2
    fi

    ARCHIVE_PREFIX="$prefix"
}

# --- provision --------------------------------------------------------------

install_prefix=""
install_major=""

if [[ "$CHECK" == "1" ]]; then
    if install_prefix="$(find_llvm "$WANT_MAJOR")"; then
        echo "LLVM $WANT_MAJOR: $install_prefix"
    else
        echo "LLVM $WANT_MAJOR: not found (run scripts/setup-llvm.sh to install it)"
    fi
    recorded="$(head -1 "$REPO_ROOT/.pep/llvm-prefix" 2>/dev/null || true)"
    echo ".pep/llvm-prefix: ${recorded:-(none)}"
    [[ -n "$install_prefix" && "$recorded" == "$install_prefix" ]]
    exit $?
fi

if install_prefix="$(find_llvm "$WANT_MAJOR")"; then
    install_major="$WANT_MAJOR"
    echo "Using LLVM $WANT_MAJOR at $install_prefix"
elif [[ "$USE_PACKAGES" == "1" ]] && install_via_packages "$WANT_MAJOR" \
     && install_prefix="$(find_llvm "$WANT_MAJOR")"; then
    install_major="$WANT_MAJOR"
    echo "Installed LLVM $WANT_MAJOR at $install_prefix"
else
    install_from_archive "$WANT_MAJOR"
    install_prefix="$ARCHIVE_PREFIX"
    install_major="$WANT_MAJOR"
    usable_llvm "$install_prefix/bin/llvm-config" "$WANT_MAJOR" >/dev/null || {
        echo "unpacked tree at $install_prefix is missing pieces the build needs" >&2
        exit 1
    }
    echo "Installed LLVM $WANT_MAJOR to $install_prefix"
fi

# iOS links with LLVM's ld64.lld, which Homebrew's llvm@<major> no longer
# ships: it is the separate lld@<major> formula (#240). A macOS build links
# with the system's ld64 and needs neither.
lld_bin=""
if [[ "$(uname -s)" == "Darwin" ]]; then
    if [[ -x "$install_prefix/bin/ld64.lld" ]]; then
        lld_bin="$install_prefix/bin"
    elif [[ "$USE_PACKAGES" == "1" ]] && command -v brew >/dev/null 2>&1 \
         && brew install "lld@$install_major"; then
        lld_bin="$(brew --prefix "lld@$install_major")/bin"
    fi
    if [[ -n "$lld_bin" ]]; then
        echo "Linker for iOS: $lld_bin/ld64.lld"
    else
        echo "warning: no ld64.lld for iOS links; 'brew install lld@$install_major' installs it" >&2
    fi
fi

# In GitHub Actions, put Homebrew's keg-only LLVM and lld first on the PATH
# of the job's later steps, so the compiler links with that clang and finds
# ld64.lld rather than using Apple's clang, which has no lld.
if [[ "$(uname -s)" == "Darwin" && -n "${GITHUB_PATH:-}" ]]; then
    echo "$install_prefix/bin" >> "$GITHUB_PATH"
    [[ -z "$lld_bin" ]] || echo "$lld_bin" >> "$GITHUB_PATH"
fi

# Unlike Windows -- where lldb has to be pulled out of a separate installer --
# Unix LLVM distributions normally carry lldb in the same prefix, and a distro
# lldb debugs these binaries fine. So this only reports what is available and
# how to get it, rather than installing a second toolchain.

# An lldb binary that exists is not necessarily usable: the release tarballs
# link liblldb against a specific libpython, which is often absent, so lldb
# dies at load time. Probe by running it.
working_lldb() {
    local lldb="$1"
    [[ -x "$lldb" ]] || return 1
    "$lldb" --version >/dev/null 2>&1
}

check_devtools() {
    # Two statements: bash 3.2 (macOS) expands the array before 'prefix' is set.
    local prefix="$1"
    local candidates=("$prefix/bin/lldb")
    command -v lldb >/dev/null 2>&1 && candidates+=("$(command -v lldb)")

    for lldb in "${candidates[@]}"; do
        if working_lldb "$lldb"; then
            echo "Debugger: $lldb ($("$lldb" --version 2>/dev/null | head -1))"
            return 0
        fi
    done

    echo "Debugger: no working lldb found." >&2
    case "$(uname -s)" in
        Darwin)
            echo "  Xcode ships one: 'xcode-select --install', or 'brew install llvm' for" >&2
            echo "  a matching lldb." >&2
            ;;
        *)
            echo "  Install your distro's package, e.g. 'sudo apt install lldb'." >&2
            ;;
    esac
    echo "  An lldb that exists but fails to start is usually missing" >&2
    echo "  libpython3.$LLDB_PYTHON_MINOR." >&2
    return 0
}

if [[ "$DEVTOOLS" == "1" ]]; then
    check_devtools "$install_prefix"
else
    echo "Devtools: skipped (--devtools to check for a debugger)"
fi

# The scripts and workflows read the prefix from .pep/llvm-prefix (gitignored,
# like all of .pep/).
mkdir -p "$REPO_ROOT/.pep"
printf '%s\n' "$install_prefix" > "$REPO_ROOT/.pep/llvm-prefix"
echo "Wrote $REPO_ROOT/.pep/llvm-prefix"
