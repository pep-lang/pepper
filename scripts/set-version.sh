#!/usr/bin/env bash
# Stamps a release version into the checkout, in every place a tool reads
# its own version from:
#
#   VERSION           the version, one line: what the scripts and workflows
#                     read, and what `pep-doc check` holds the tools to
#   tools/*/main.pep  each Pepper tool's `version()`
#   tools/pep-lsp/arguments.pep  pep-lsp's `export version()`
#
#   scripts/set-version.sh <version>
#
# Main holds the version being developed, as a prerelease (`0.4.0-dev`),
# which every build of main reports and the release workflow publishes on
# each merge. Making release 0.4.0 by hand: set 0.4.0 and tag
# v0.4.0 (any version: release.yml builds it with the newest build of main);
# release.yml then opens the pull request that sets 0.5.0-dev.
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

printf '%s\n' "$version" > VERSION

# The Pepper tools: each `version()` returns the release it belongs to. A
# tool's is in its main.pep, except pep-lsp's, which is `export`ed from
# its arguments.pep.
versions=(tools/*/main.pep tools/pep-lsp/arguments.pep)
for source in "${versions[@]}"; do
  if grep -Eq '^(export )?version\(\): String \{' "$source"; then
    replace "$source" "return \"$current\";" "return \"$version\";"
  fi
done

# Nothing may still claim the old version.
stale="$(grep -lF "return \"$current\";" "${versions[@]}" || true)"
if [ -n "$stale" ]; then
  echo "error: still at $current: $stale" >&2
  exit 1
fi
echo "VERSION: $(cat VERSION)"
