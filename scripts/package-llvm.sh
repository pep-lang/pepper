#!/usr/bin/env bash
# Build a minimal LLVM package for CI out of a full install prefix.
#
# The official releases are enormous -- 11.6 GB extracted on Linux, 9 GB of
# that being unstripped tools this project never invokes -- which is what
# exhausts a GitHub runner's disk. What the build actually consumes is
# llvm-config (for llvm-sys discovery) and the static component archives (for
# linking), about 313 MB.
#
# clang is deliberately excluded: crates/pepper-driver/src/linker.rs prefers
# the prefix's clang but falls back to clang on PATH, and both the Linux and
# macOS runners ship one. Including it would add gigabytes to package a
# compiler we only use as a link driver.
#
# Usage: scripts/package-llvm.sh <prefix> <output.tar.xz>
set -euo pipefail

prefix="${1:?usage: package-llvm.sh <prefix> <output.tar.xz>}"
output="${2:?usage: package-llvm.sh <prefix> <output.tar.xz>}"

[ -x "$prefix/bin/llvm-config" ] || {
  echo "no llvm-config in $prefix" >&2
  exit 1
}

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

mkdir -p "$staging/bin" "$staging/lib"
cp "$prefix/bin/llvm-config" "$staging/bin/"

# llvm-config --libs names these; a missing one is a link error much later.
#
# Counted with find, not `ls ... | wc -l`: under `set -euo pipefail` a
# non-matching glob makes ls exit 2, pipefail propagates it out of the
# command substitution, and the script dies here printing nothing at all --
# so the guard below, which exists precisely to explain this case, never runs.
archives=$(find "$prefix/lib" -maxdepth 1 -name 'libLLVM*.a' | wc -l)
[ "$archives" -gt 0 ] || { echo "no libLLVM*.a archives in $prefix/lib" >&2; exit 1; }
cp "$prefix"/lib/libLLVM*.a "$staging/lib/"

# Anything else llvm-config reports as a link dependency of the components.
for extra in "$prefix"/lib/libLLVM*.so*; do
  [ -e "$extra" ] && cp -P "$extra" "$staging/lib/"
done

# llvm-sys also compiles a small C shim (wrappers/*.c) against the C API, so
# the C headers travel with the package: llvm-c itself plus llvm/Config, which
# llvm-c/Target.h pulls in for the target .def lists. A couple of MB; the C++
# headers are not needed.
for headers in include/llvm-c include/llvm/Config; do
  [ -d "$prefix/$headers" ] || { echo "no $headers in $prefix" >&2; exit 1; }
  mkdir -p "$staging/$(dirname "$headers")"
  cp -R "$prefix/$headers" "$staging/$headers"
done

echo "packaging $archives archives from $prefix"
du -sm "$staging" | awk '{print "  staged: " $1 " MB"}'

mkdir -p "$(dirname "$output")"
tar -C "$staging" -cJf "$output" .
du -m "$output" | awk '{print "  package: " $1 " MB"}'
