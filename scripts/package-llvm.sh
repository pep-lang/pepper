#!/usr/bin/env bash
# Build a minimal LLVM package for CI out of a full install prefix.
#
# The official releases are enormous -- 11.6 GB extracted on Linux, 9 GB of
# that being unstripped tools this project never invokes -- which is what
# exhausts a GitHub runner's disk. What the build actually consumes is
# llvm-config (for discovery), the libraries (for linking) and the C
# headers: 83 MB compressed on Windows, 123 MB on macOS arm64.
#
# clang is deliberately excluded: tools/compiler/driver/linker.pep prefers
# the prefix's clang but falls back to clang on PATH, and both the Linux and
# macOS runners ship one. Including it would add gigabytes to package a
# compiler we only use as a link driver.
#
# tar reads the keep-set straight out of the prefix rather than a staging copy.
# Staging cost a second copy of everything -- 435 MB on the macOS leg -- on the
# same filesystem as the 11.6 GB tree it was copied from, which is exactly the
# disk this job does not have. `cp -l` is not the portable way out: macOS cp
# documents -l but fails with EBADF, and TMPDIR is not guaranteed to share a
# filesystem with the prefix.
#
# Usage: scripts/package-llvm.sh <prefix> <output.tar.xz>
set -euo pipefail

prefix="${1:?usage: package-llvm.sh <prefix> <output.tar.xz>}"
output="${2:?usage: package-llvm.sh <prefix> <output.tar.xz>}"

[ -x "$prefix/bin/llvm-config" ] || {
  echo "no llvm-config in $prefix" >&2
  exit 1
}

# Resolved before the cd below, and while the directory is guaranteed to exist,
# so a relative output path still lands where the caller asked.
mkdir -p "$(dirname "$output")"
output="$(cd "$(dirname "$output")" && pwd)/$(basename "$output")"

cd "$prefix"

# Members are named relative to the prefix, so the archive unpacks straight
# over a prefix root with no --strip-components.
#
# nullglob matters: without it a non-matching glob is passed to tar verbatim
# and tar fails on a file called `libLLVM*.a`. The guards below then report
# which piece is actually missing.
shopt -s nullglob

# llvm-config --libs names these; a missing one is a link error much later.
members=(lib/libLLVM*.a)
[ "${#members[@]}" -gt 0 ] || { echo "no libLLVM*.a archives in $prefix/lib" >&2; exit 1; }
archives="${#members[@]}"

# Anything else llvm-config reports as a link dependency of the components.
#
# libPolly is named by `llvm-config --libnames --link-static` on prefixes that
# ship it -- Debian splits it into libpolly-N-dev -- and a static link of LLVM
# hands every name it gets to the linker. Leaving it out produced a package that
# setup-llvm.sh's own usable_llvm check would reject, with the failure
# surfacing as "could not find native static library Polly" at link time.
# Keep this set in step with archive_members() in scripts/setup-llvm.sh.
members+=(lib/libLLVM*.so* lib/libLLVM*.dylib lib/libPolly*.a)
members+=(bin/llvm-config)

# The C headers travel with the package, so the prefix is a complete C API
# install (setup-llvm.sh's usable_llvm checks for them): llvm-c itself plus
# llvm/Config, which llvm-c/Target.h pulls in for the target .def lists. A
# couple of MB; the C++ headers are not needed.
for headers in include/llvm-c include/llvm/Config; do
  [ -d "$headers" ] || { echo "no $headers in $prefix" >&2; exit 1; }
  members+=("$headers")
done

echo "packaging $archives archives from $prefix"
du -cm "${members[@]}" | awk 'END {print "  selected: " $1 " MB"}'

tar -cJf "$output" "${members[@]}"
du -m "$output" | awk '{print "  package: " $1 " MB"}'
