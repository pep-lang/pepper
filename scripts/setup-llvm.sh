#!/usr/bin/env bash
# Provision the LLVM toolchain that llvm-sys (via inkwell) links against, and
# point cargo at it. macOS / Linux counterpart of scripts/setup-llvm.ps1.
#
# llvm-sys finds LLVM by running `<prefix>/bin/llvm-config` and matching its
# major version, so an install that ships llvm-config is required. A system
# LLVM of the right major version is used when present (Homebrew, apt.llvm.org,
# distro packages); otherwise the official release tarball is downloaded to
# ~/.local/share/pepper/llvm/<version>.
#
# Usage:
#   ./scripts/setup-llvm.sh [--devtools]
#
#   --devtools   also make sure a debugger (lldb) is available; equivalent to
#                PEPPER_SETUP_DEVTOOLS=1. Off by default: the build does not
#                need it.
#
# Idempotent: re-running with a usable toolchain only rewrites .cargo/config.toml.
set -euo pipefail

# Dictated by the inkwell feature in crates/*/Cargo.toml:
#   inkwell "llvm22-1" -> llvm-sys 221.x -> LLVM 22.1.x
#
# Changing this? Re-run the llvm-package workflow afterwards
# (gh workflow run llvm-package.yml). The CI packages are per-version, and a
# missing one does not fail: CI silently reverts to multi-GB full installs.
# This line is also parsed by ci-provision-llvm.sh and llvm-package.yml, so
# keep the `LLVM_VERSION="<version>"` shape.
LLVM_VERSION="22.1.8"
LLVM_MAJOR="22"
LLVM_SYS_MAJOR="221"

# CPython minor version liblldb is linked against in this LLVM release; only
# used to make the "lldb won't start" hint concrete.
LLDB_PYTHON_MINOR="11"

# PEPPER_SETUP_DEVTOOLS lets a dev opt in once (shell profile / CI) instead of
# remembering the flag on every run.
DEVTOOLS=0
case "${PEPPER_SETUP_DEVTOOLS:-}" in
    ""|0|false|no) ;;
    *) DEVTOOLS=1 ;;
esac
for arg in "$@"; do
    case "$arg" in
        --devtools) DEVTOOLS=1 ;;
        --no-devtools) DEVTOOLS=0 ;;
        -h|--help)
            sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "unknown argument: $arg" >&2
            exit 2
            ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/pepper"
PREFIX="$ROOT/llvm/$LLVM_VERSION"
CACHE_DIR="$ROOT/cache"

# Report the prefix of an llvm-config whose major version matches, else nothing.
probe_llvm_config() {
    local config="$1"
    command -v "$config" >/dev/null 2>&1 || return 1
    local version
    version="$("$config" --version 2>/dev/null)" || return 1
    [[ "${version%%.*}" == "$LLVM_MAJOR" ]] || return 1
    "$config" --prefix 2>/dev/null
}

find_system_llvm() {
    local candidates=("llvm-config-$LLVM_MAJOR" "llvm-config")
    # Homebrew keeps versioned LLVM off PATH.
    if command -v brew >/dev/null 2>&1; then
        local brew_prefix
        for formula in "llvm@$LLVM_MAJOR" llvm; do
            brew_prefix="$(brew --prefix "$formula" 2>/dev/null || true)"
            [[ -n "$brew_prefix" ]] && candidates+=("$brew_prefix/bin/llvm-config")
        done
    fi
    candidates+=("/usr/lib/llvm-$LLVM_MAJOR/bin/llvm-config")

    for candidate in "${candidates[@]}"; do
        local prefix
        if prefix="$(probe_llvm_config "$candidate")"; then
            printf '%s' "$prefix"
            return 0
        fi
    done
    return 1
}

# Official tarball for this host. Naming differs per platform and release, so
# keep this table next to the version constant above.
release_asset() {
    local os arch
    os="$(uname -s)"
    arch="$(uname -m)"
    case "$os/$arch" in
        Darwin/arm64)          printf 'LLVM-%s-macOS-ARM64.tar.xz' "$LLVM_VERSION" ;;
        Linux/x86_64)          printf 'LLVM-%s-Linux-X64.tar.xz' "$LLVM_VERSION" ;;
        Linux/aarch64|Linux/arm64) printf 'LLVM-%s-Linux-ARM64.tar.xz' "$LLVM_VERSION" ;;
        *)
            echo "no prebuilt LLVM $LLVM_VERSION for $os/$arch." >&2
            echo "Install LLVM $LLVM_MAJOR with llvm-config (e.g. 'brew install llvm@$LLVM_MAJOR'" >&2
            echo "or https://apt.llvm.org) and re-run this script." >&2
            return 1
            ;;
    esac
}

usable_prefix() {
    local prefix="$1"
    [[ -x "$prefix/bin/llvm-config" ]] || return 1
    local version
    version="$("$prefix/bin/llvm-config" --version 2>/dev/null)" || return 1
    [[ "${version%%.*}" == "$LLVM_MAJOR" ]]
}

install_prefix=""
if system_prefix="$(find_system_llvm)"; then
    echo "Using system LLVM $LLVM_MAJOR at $system_prefix"
    install_prefix="$system_prefix"
elif usable_prefix "$PREFIX"; then
    echo "LLVM $LLVM_VERSION already installed at $PREFIX"
    install_prefix="$PREFIX"
else
    asset="$(release_asset)"
    url="https://github.com/llvm/llvm-project/releases/download/llvmorg-$LLVM_VERSION/$asset"
    archive="$CACHE_DIR/$asset"

    mkdir -p "$CACHE_DIR"
    if [[ ! -f "$archive" ]]; then
        echo "Downloading $asset ..."
        curl -L --fail --progress-bar -o "$archive.part" "$url"
        mv "$archive.part" "$archive"
    else
        echo "Using cached $archive"
    fi

    echo "Extracting to $PREFIX ..."
    rm -rf "$PREFIX"
    mkdir -p "$PREFIX"
    tar -xf "$archive" -C "$PREFIX" --strip-components=1

    usable_prefix "$PREFIX" || {
        echo "extracted tree at $PREFIX has no usable bin/llvm-config" >&2
        exit 1
    }
    echo "Installed LLVM $LLVM_VERSION to $PREFIX"
    install_prefix="$PREFIX"
fi

# Unlike Windows -- where lldb has to be pulled out of a separate installer --
# Unix LLVM distributions normally carry lldb in the same prefix, and a distro
# lldb debugs these binaries fine. So this only reports what is available and
# how to get it, rather than installing a second toolchain.

# An lldb binary that exists is not necessarily usable: the release tarballs
# link liblldb against a specific libpython, which is often absent, so lldb
# dies at load time. Probe by running it.
working_lldb() {
    local candidate="$1"
    local out
    out="$("$candidate" --version 2>&1)" || return 1
    [[ "$out" == *lldb* ]] || return 1
    printf '%s' "$out" | head -1
}

check_devtools() {
    local reported
    if [[ -x "$install_prefix/bin/lldb" ]]; then
        if reported="$(working_lldb "$install_prefix/bin/lldb")"; then
            echo "Debugger: $reported"
            return 0
        fi
        echo "Debugger: $install_prefix/bin/lldb is present but will not run" >&2
        echo "  (usually a missing libpython for liblldb; install python3.$LLDB_PYTHON_MINOR" >&2
        echo "   or use the distro lldb instead)" >&2
    fi
    if command -v lldb >/dev/null 2>&1 && reported="$(working_lldb lldb)"; then
        echo "Debugger: $reported (from PATH)"
        return 0
    fi
    echo "Debugger: no usable lldb found." >&2
    case "$(uname -s)" in
        Darwin) echo "  Install with: brew install llvm@$LLVM_MAJOR   (or use Xcode's lldb)" >&2 ;;
        *)      echo "  Install with: apt install lldb-$LLVM_MAJOR    (see https://apt.llvm.org)" >&2 ;;
    esac
    # Not fatal: the build and tests do not need a debugger.
    return 0
}

if [[ "$DEVTOOLS" == "1" ]]; then
    check_devtools
else
    echo "Skipping debugger check; re-run with --devtools (or PEPPER_SETUP_DEVTOOLS=1)."
fi

# Point cargo at the prefix. `.cargo/config.toml` [env] reaches build scripts,
# so llvm-sys sees it with no shell state -- `cargo build` just works.
mkdir -p "$REPO_ROOT/.cargo"
cat > "$REPO_ROOT/.cargo/config.toml" <<EOF
# Generated by scripts/setup-llvm.sh -- do not edit, do not commit.
# The path is machine-specific; re-run the script on a new machine.
[env]
LLVM_SYS_${LLVM_SYS_MAJOR}_PREFIX = "$install_prefix"
EOF

echo "Wrote $REPO_ROOT/.cargo/config.toml (LLVM_SYS_${LLVM_SYS_MAJOR}_PREFIX)"
echo "Run 'cargo build' to verify."
