#!/usr/bin/env bash
# Diagnostic: install LLVM from this platform's package manager and find out
# whether the result actually builds and tests the workspace. Run through
# platform-test with provision=false:
#
#   gh workflow run platform-test.yml --ref <branch> \
#     -f platforms=linux,macos -f provision=false \
#     -f script="bash scripts/probe-llvm-packages.sh"
#
# "Sufficient" is not "llvm-config exists". llvm-sys runs
# `llvm-config --libnames --link-static`, falls back to `--link-shared`, links
# every name it gets out of `--libdir`, and compiles a C shim against the
# llvm-c headers -- so the only trustworthy check is a real build and test run,
# which is what this does for every version the package manager can reach.
#
# Deliberately not `set -e`: a version failing is a result, not a reason to
# stop testing the others.
set -uo pipefail

section() { printf '\n=== %s\n' "$*"; }

# Resolve every library llvm-sys would ask the linker for, and report the ones
# that are not on disk -- the failure that otherwise surfaces as a link error
# hundreds of lines into a cargo build.
inventory() {
    local config="$1" libdir includedir kind names missing count
    libdir="$("$config" --libdir 2>/dev/null)"
    includedir="$("$config" --includedir 2>/dev/null)"
    echo "  version: $("$config" --version 2>/dev/null)   prefix: $("$config" --prefix 2>/dev/null)"
    echo "  size:    $(du -sm "$("$config" --prefix)" 2>/dev/null | cut -f1) MB"
    for kind in static shared; do
        names="$("$config" --libnames "--link-$kind" 2>&1)"
        if [ -z "$names" ] || printf '%s' "$names" | grep -i 'error\|not available' >/dev/null; then
            echo "  $kind: unavailable"
            continue
        fi
        count=0; missing=0
        for name in $names; do
            count=$((count + 1))
            if [ ! -e "$libdir/$name" ]; then
                missing=$((missing + 1))
                [ "$missing" -le 4 ] && echo "    missing: $name"
            fi
        done
        echo "  $kind: $count named, $missing missing"
    done
    for header in llvm-c/Core.h llvm/Config/llvm-config.h; do
        [ -e "$includedir/$header" ] || echo "  header MISSING: $header"
    done
}

# The real question: does the workspace build and pass its tests against this
# prefix? Feature name and llvm-sys variable are both derived from the major,
# exactly as the setup scripts will have to do.
try_build() {
    local major="$1" prefix="$2" feature="llvm$1-1" var="LLVM_SYS_${1}1_PREFIX"
    section "build+test against LLVM $major at $prefix"
    inventory "$prefix/bin/llvm-config"

    local start=$SECONDS
    if env "$var=$prefix" cargo build --quiet --no-default-features --features "$feature" 2>&1 | tail -25; then
        echo "  BUILD OK ($((SECONDS - start))s)"
    else
        echo "  BUILD FAILED ($((SECONDS - start))s)"
        return 1
    fi

    # Captured once: running it twice, as this did, doubled both the runner
    # time per version and the elapsed figure reported below.
    start=$SECONDS
    local output
    output="$(env "$var=$prefix" cargo test --no-default-features --features "$feature" --workspace 2>&1)"
    printf '%s\n' "$output" | grep -E "^test result|^error|panicked|FAILED" | head -20
    printf '  test pass count: %s (%ss)\n' \
        "$(printf '%s\n' "$output" | grep -oE '[0-9]+ passed' | awk '{p+=$1} END {print p}')" \
        "$((SECONDS - start))"
}

section "host"
uname -sm
[ -r /etc/os-release ] && { . /etc/os-release; echo "$PRETTY_NAME"; }
sw_vers -productVersion 2>/dev/null
df -m . | tail -1 | awk '{print "free: " $4 " MB"}'

case "$(uname -s)" in
Linux)
    section "apt candidates (supported majors only)"
    avail=''
    for n in 18 19 20 21 22; do
        cand="$(LC_ALL=C apt-cache policy "llvm-$n-dev" 2>/dev/null | awk '/Candidate:/ {print $2}')"
        if [ -n "$cand" ] && [ "$cand" != "(none)" ]; then
            printf '  llvm-%s-dev %s' "$n" "$cand"
            # Polly is named by --libnames but packaged separately on Debian.
            poll="$(LC_ALL=C apt-cache policy "libpolly-$n-dev" 2>/dev/null | awk '/Candidate:/ {print $2}')"
            [ -n "$poll" ] && [ "$poll" != "(none)" ] && printf '   (libpolly-%s-dev %s)' "$n" "$poll"
            printf '\n'
            avail="${avail:+$avail }$n"
        fi
    done

    section "already on the image"
    for d in /usr/lib/llvm-*; do
        [ -x "$d/bin/llvm-config" ] && echo "$d has llvm-config ($("$d/bin/llvm-config" --version))"
    done

    sudo apt-get update -qq
    for n in $avail; do
        section "apt install llvm-$n-dev"
        start=$SECONDS
        pkgs="llvm-$n-dev"
        # awk, not `grep -q`: -q exits early, apt-cache dies of SIGPIPE, and
        # pipefail then reports the test as false -- a race that silently drops
        # libpolly and makes the prefix unusable.
        polly="$(LC_ALL=C apt-cache policy "libpolly-$n-dev" 2>/dev/null | awk '/Candidate:/ {print $2}')"
        [ -n "$polly" ] && [ "$polly" != "(none)" ] && pkgs="$pkgs libpolly-$n-dev"
        echo "  packages: $pkgs"
        sudo apt-get install -y -qq $pkgs >/dev/null 2>&1 \
            && echo "  installed in $((SECONDS - start))s" \
            || echo "  install FAILED"
        try_build "$n" "/usr/lib/llvm-$n"
        df -m . | tail -1 | awk '{print "  free now: " $4 " MB"}'
    done
    ;;
Darwin)
    section "brew formulae"
    brew list --versions 2>/dev/null | grep -i '^llvm'
    for n in 18 19 20 21 22; do
        prefix="$(brew --prefix "llvm@$n" 2>/dev/null)"
        [ -n "$prefix" ] || continue
        if [ ! -x "$prefix/bin/llvm-config" ]; then
            section "brew install llvm@$n"
            start=$SECONDS
            brew install "llvm@$n" >/dev/null 2>&1 \
                && echo "  installed in $((SECONDS - start))s" \
                || { echo "  install FAILED"; continue; }
        else
            echo "llvm@$n already present at $prefix"
        fi
        try_build "$n" "$prefix"
    done
    ;;
esac

section "done"
