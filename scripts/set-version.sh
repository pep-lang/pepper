#!/usr/bin/env bash
# Stamps a release version into the checkout, in every place a tool reads
# its own version from:
#
#   VERSION           the version, one line: what the scripts and workflows
#                     read, and what `pep-doc check` holds the tools to
#   tools/*/main.pep  each Pepper tool's `version()`
#   Cargo.toml        [workspace.package] version (the Rust build), while
#                     it exists
#   Cargo.lock        the workspace packages' entries, so --locked builds
#
#   scripts/set-version.sh <version>
#
# Main holds the version being developed, as a prerelease (`0.4.0-dev`),
# which every build of main reports and the release workflow publishes on
# each merge (#713). Making release 0.4.0 by hand: set 0.4.0 and tag
# v0.4.0; release.yml then opens the pull request that sets 0.5.0-dev.
# It fails when a file does not hold the current version where expected,
# so a tool that moves its version cannot be released under the old one
# unnoticed.
set -euo pipefail

version="${1:?usage: set-version.sh <version>}"
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
  echo "error: '$version' is not a version such as 0.4.0 or 0.4.0-dev" >&2
  exit 2
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

current="$(tr -d '\r' < VERSION)"
if [ -z "$current" ]; then
  echo "error: VERSION holds no version" >&2
  exit 1
fi
echo "version $current -> $version"
if [ "$current" = "$version" ]; then
  exit 0
fi

# Replaces `from` with `to` in `file`, failing when `from` is not there.
replace() {
  local file="$1" from="$2" to="$3"
  if ! grep -qF -- "$from" "$file"; then
    echo "error: $file does not hold '$from'" >&2
    exit 1
  fi
  local temp="$file.set-version"
  awk -v from="$from" -v to="$to" '{
    line = $0
    out = ""
    while ((i = index(line, from)) > 0) {
      out = out substr(line, 1, i - 1) to
      line = substr(line, i + length(from))
    }
    print out line
  }' "$file" > "$temp"
  mv "$temp" "$file"
}

# The Rust build's files, until it is deleted (#225).
if [ -f Cargo.toml ]; then
  # Cargo.toml: only the [workspace.package] line.
  held="$(awk '/^\[workspace\.package\]/ { in_package = 1; next }
    /^\[/ { in_package = 0 }
    in_package && /^version *=/ { gsub(/.*= *"|".*/, ""); print; exit }' Cargo.toml)"
  if [ "$held" != "$current" ]; then
    echo "error: Cargo.toml's [workspace.package] version is '$held', not VERSION's $current" >&2
    exit 1
  fi
  awk -v from="$current" -v to="$version" '
    /^\[workspace\.package\]/ { in_package = 1 }
    /^\[/ && !/^\[workspace\.package\]/ { in_package = 0 }
    in_package && /^version *=/ { sub("\"" from "\"", "\"" to "\"") }
    { print }' Cargo.toml > Cargo.toml.set-version
  mv Cargo.toml.set-version Cargo.toml
fi
if [ -f Cargo.lock ]; then
  # Cargo.lock: the workspace's own packages, which have no `source` line.
  workspace_packages=" pepper pepper-codegen pepper-driver pepper-files pepper-parser pepper-sema xtask "
  awk -v from="$current" -v to="$version" -v names="$workspace_packages" '
    /^name = / { name = $3; gsub(/"/, "", name) }
    /^version = / && index(names, " " name " ") > 0 { sub("\"" from "\"", "\"" to "\"") }
    { print }' Cargo.lock > Cargo.lock.set-version
  mv Cargo.lock.set-version Cargo.lock
fi

printf '%s\n' "$version" > VERSION

# The Pepper tools: each `version()` returns the release it belongs to.
for main in tools/*/main.pep; do
  if grep -q '^version(): String {' "$main"; then
    replace "$main" "return \"$current\";" "return \"$version\";"
  fi
done

# Nothing may still claim the old version.
stale="$(grep -lF "return \"$current\";" tools/*/main.pep || true)"
if [ -n "$stale" ]; then
  echo "error: still at $current: $stale" >&2
  exit 1
fi
if [ -f Cargo.toml ] && ! grep -q "^version = \"$version\"" Cargo.toml; then
  echo "error: Cargo.toml is not at $version" >&2
  exit 1
fi
echo "VERSION: $(cat VERSION)"
